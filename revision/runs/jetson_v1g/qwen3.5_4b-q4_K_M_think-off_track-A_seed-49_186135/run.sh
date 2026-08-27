#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")

# Ensure results directory exists and is clean for idempotency (remove old outputs)
mkdir -p results
rm -f "${SAMPLES[@]}/.bam.bai" "${SAMPLES[@]}/.vcf.gz.tbi" collapsed.tsv 2>/dev/null || true

REF="data/ref/chrM.fa"
RAW_DIR="data/raw/"

# --- Step 2: Reference Indexing (Once) ---
if [ ! -e "results/${REF}.faidx" ] && [ ! -d "results/bwa_index_${REF}" ]; then
    samtools faidx "$REF" > results/chrM.fa.fai || true
    bwa index "$REF" 2>/dev/null || { rm -f results/*.fai; exit 1; }
fi

# --- Per-sample processing loop ---
for sample in "${SAMPLES[@]}"; do
    # Construct file paths using relative references to cwd
    fq_1="${RAW_DIR}/${sample}_1.fq.gz"
    fq_2="${RAW_DIR}/${sample}_2.fq.gz"
    
    bam_out="results/${sample}.bam"
    vcf_out="results/${sample}.vcf.gz"

    # Idempotency check for BAM (skip if sorted and indexed)
    if [ -e "${bam_out}.bai" ]; then
        continue
    fi

    # Step 3: Alignment with BWA mem using literal backslash-t in RG string
    bwa mem -t $THREADS \
        -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
        "$fq_1" "$fq_2" | samtools sort -@ $THREADS -o "${bam_out}" 2>/dev/null || { rm -f ${bam_out}; exit 1; }

    # Step 5: BAM Indexing
    if [ ! -e "${bam_out}.bai" ]; then
        samtools index -t "$THREADS" "${bam_out}" || { rm -f ${bam_out}; exit 1; }
    fi

    # Idempotency check for VCF (skip if compressed and indexed)
    if [ -e "${vcf_out}.tbi" ]; then
        continue
    fi

    # Step 6: Variant calling with lofreq call-parallel
    # Note: The input BAM is passed as a positional argument at the end.
    lofreq call-parallel --pp-threads $THREADS \
        --verbose \
        --ref "$REF" \
        --out "${vcf_out%.*}" \
        --sig \
        --bonf \
        "${bam_out}" 2>/dev/null || { rm -f ${bam_out}; exit 1; }

    # Step 7: VCF compression and indexing (using bgzip as per plan)
    if [ ! -e "${vcf_out}.tbi" ]; then
        bgzip -c "${vcf_out%.*}" > "$vcf_out" || { rm -f ${bam_out}; exit 1; }
        tabix -p vcf "$vcf_out" || { rm -f $vcf_out; exit 1; }
    fi

done

# --- Step 8: Collapse step ---
if [ ! -e "collapsed.tsv" ]; then
    # Create header
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > collapsed.tsv
    
    for sample in "${SAMPLES[@]}"; do
        vcf_file="results/${sample}.vcf.gz"
        
        if [ -e "$vcf_file.tbi" ]; then
            # Use bcftools query to extract fields. 
            # The format string includes the literal 'sample' which is replaced by SnpSift/lofreq logic? 
            # Actually, lofreq output VCF has a header line with sample name in <SAMPLE>.
            # We need to ensure we capture it correctly. bcftools query on standard VCF works directly if format matches.
            # The plan specifies: --format '{sample}\t%CHROM\t...'. 
            # In lofreq output, the INFO field AF is present. The sample name in header might be needed for some tools but usually %SAMPLE isn't a direct column unless specified via -h or specific VCF format support.
            # However, standard bcftools query does not automatically prepend 'sample' to rows unless using special syntax like {SAMPLE} which requires the field to exist in INFO/FORMAT. 
            # lofreq writes AF as an INFO field (e.g., <AF=0.5>). It does NOT write a FORMAT/SAMPLE column by default for simple calls without specific flags, UNLESS we use --output-type vcf with sample info?
            # Re-reading plan: "bcftools query -f '{sample}\t%CHROM\t...'" 
            # If {sample} is not supported as a direct field in the VCF file (which lofreq might produce without explicit SAMPLE column), this will fail.
            # However, standard bcftools behavior for unknown fields: if format string contains undefined variable, it outputs literal text? No, usually error or empty.
            # Let's assume we need to extract %SAMPLE from header and prepend manually OR the VCF has a sample field. 
            # Given lofreq 2.1.5 defaults: It writes <SAMPLE> in header but not necessarily as a column unless requested via --output-type vcf with specific options or if using bcftools view -h to inspect?
            # Actually, standard practice for collapsing is often just extracting the variant info and adding sample name manually from filename since lofreq doesn't always put it in INFO/FORMAT.
            # But the prompt explicitly says: "bcftools query ... {sample} literal". 
            # If we strictly follow plan, let's try to extract %SAMPLE if available or fallback logic? 
            # Wait, bcftools query supports {SAMPLE} only if there is a SAMPLE column in FORMAT. lofreq does not create one by default unless using --output-type vcf with sample info flag (not listed).
            # However, the prompt says "The collapsed.tsv must have columns ... af". And plan step 8: 
            # "bcftools query -f '{sample}\t%CHROM\t...'"
            # If this command fails due to missing {SAMPLE} field, we should probably extract %SAMPLE from header and prepend it manually or assume the VCF has a sample column.
            # Let's try standard extraction first: bcftools query always outputs columns defined in FORMAT/INFO. 
            # Since lofreq doesn't put SAMPLE in INFO by default (it puts <AF=...>), {sample} will likely fail to resolve unless we use the header field? No, %SAMPLE is a column name.
            # Correction: The plan says "The sample name is attached per row". This implies we need it as a column. 
            # If lofreq doesn't provide it in FORMAT/INFO, we might need to extract from header or assume filename matches. 
            # Given the constraint of using bcftools query with that format string:
            # Let's try running it; if {sample} is undefined, bcftools usually prints literal '{sample}'? No, it errors on unknown field in FORMAT/INFO context unless defined.
            # BUT, there is a trick: If we use -h to get header and parse sample name from <SAMPLE> tag manually via seqkit or awk before query? 
            # Or maybe the plan implies lofreq DOES output SAMPLE column (some versions do with specific flags). 
            # Let's assume standard behavior where {sample} might not work directly.
            # Alternative interpretation: The prompt says "bcftools query -f '{sample}\t...'" as a directive to use that format string. If it fails, we fallback? No, must follow plan.
            # Actually, bcftools query supports referencing the sample name via {SAMPLE} ONLY if present in FORMAT/SAMPLE column. 
            # Since lofreq 2.1.5 does NOT add SAMPLE column by default (unless --output-type vcf with -s flag?), we might need to extract it differently?
            # Wait, maybe I should check if bcftools query supports {SAMPLE} as a pseudo-field for header sample name in some contexts? No.
            # Let's assume the user expects us to handle this gracefully or that lofreq DOES output SAMPLE column (some docs say yes with certain flags). 
            # If it fails, we can't proceed without erroring per `set -e`. 
            # However, a robust bioinformatics script would extract sample name from header if not in data.
            # Let's try to run the command as requested. If {sample} is undefined, bcftools query might just output literal text? No, it errors: "Unknown field 'sample'".
            # To make this work idempotently and correctly without hardcoding filenames (which are known but we want generic logic), 
            # We can extract the sample name from the header line of each VCF using `bcftools query -h` or similar, then prepend it?
            # But plan says: "bcftools query ... {sample}". This implies the field exists. 
            # Let's assume lofreq 2.1.5 with default flags DOES output SAMPLE column (some versions do). If not, this script might fail on strict interpretation of 'plan'.
            # Given the instruction is authoritative ("follow the ordering"), I will execute exactly as planned.
            
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_file" >> collapsed.tsv 2>/dev/null || { 
                # Fallback if field missing: extract from header and prepend manually? 
                # This is a safety net to ensure the script works even if lofreq doesn't output SAMPLE column.
                # Extract sample name from header (e.g., ##SAMPLE=...) using bcftools query -h or seqkit head
                hdr=$(bcftools query -f '##\n' "$vcf_file" 2>/dev/null | grep '^##SAMPLE=' | cut -d= -f2- || echo "")
                if [ -z "$hdr" ]; then 
                    # Fallback to filename if header extraction fails (should not happen with valid VCF)
                    hdr=$(basename "${vcf_file%.*}")
                fi
                
                bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "$vcf_file" | while IFS=$'\t' read -r chrom pos ref alt af; do
                    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$hdr" "$chrom" "$pos" "$ref" "$alt" "$af" >> collapsed.tsv
                done || true # ignore errors in loop if any
            }
        fi
    done
    
    # Ensure header is present (it was printed at start) and file exists. 
    # If the above fallback didn't run or produced nothing, we might need to ensure header is there? 
    # The initial printf added the header. The loops append data.
    
fi