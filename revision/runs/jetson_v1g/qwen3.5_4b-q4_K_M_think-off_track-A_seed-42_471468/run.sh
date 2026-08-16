#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"
RESULTS_DIR="results"

mkdir -p "$RESULTS_DIR"

# Reference indexing (once)
if [[ ! -f "${REF}.fai" ]] || [[ $(stat -c %Y ${REF}.fai 2>/dev/null || echo 0) -lt $(date +%s) ]]; then
    samtools faidx "$REF" > /dev/null
fi

# BWA index (once)
if [[ ! -d "${REF}"*.amb ]] && [[ ! -e "${REF}".bwt ]]; then
    bwa index "$REF" > /dev/null
fi

for sample in "${SAMPLES[@]}"; do
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    
    # Check if all outputs exist and are newer than inputs (idempotency)
    vcf_tbi="${RESULTS_DIR}/${sample}.vcf.gz.tbi"
    bai="${RESULTS_DIR}/${sample}.bam.bai"
    bam="${RESULTS_DIR}/${sample}.bam"
    ref_idx="${REF}".amb
    
    if [[ -e "$bai" ]] && [[ $(stat -c %Y $bai) -gt $(stat -c %Y ${fq1}) ]] \
       && [[ $(stat -c %Y $bai) -gt $(stat -c %Y ${fq2}) ]]; then
        continue
    fi
    
    # Step 3: Alignment with bwa mem (using literal backslash-t for RG line as per spec)
    if ! command -v bwa > /dev/null; then exit 1; fi
    if [[ $(bwa --version | head -n1 | cut -d' ' -f2) < "0.7" ]]; then exit 1; fi
    
    RG_LINE="@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA"
    
    bwa mem -t $THREADS "$REF" \
        -R "${RG_LINE}" \
        "$fq1" "$fq2" 2>/dev/null | samtools sort -@ $THREADS -o "$bam" || exit 1
    
    # Step 5: BAM indexing
    if ! command -v samtools > /dev/null; then exit 1; fi
    samtools index -t -a -@ $THREADS "$bam" || exit 1
    
    # Step 6: Variant calling with lofreq call-parallel (positional args)
    if [[ $(lofreq --version | head -n1 | cut -d' ' -f2) < "2.0" ]]; then exit 1; fi
    lofreq call-parallel \
        --pp-threads $THREADS \
        --verbose \
        --ref "$REF" \
        --out "${RESULTS_DIR}/${sample}.vcf" \
        --sig \
        --bonf \
        "$bam" || exit 1
    
    # Step 7: VCF compression and indexing (remove uncompressed)
    if ! command -v bgzip > /dev/null; then exit 1; fi
    if [[ $(bgzip --version | head -n1 | cut -d' ' -f2) < "0.9" ]]; then exit 1; fi
    
    # Remove old vcf before compressing to ensure clean state, but keep tbi/bam for now
    rm -f "${RESULTS_DIR}/${sample}.vcf"
    
    bgzip -c "${RESULTS_DIR}/${sample}.vcf.gz.tib" > "${RESULTS_DIR}/${sample}.vcf.gz" 2>/dev/null || \
        (bgzip -c <(samtools view "$bam") | bcftools query -Oz -o "${RESULTS_DIR}/${sample}.vcf.gz" && rm -f "${RESULTS_DIR}/${sample}.vcf.gz.tib"); then
    
    # Re-index if needed or just ensure it exists. If bgzip failed, we might need tabix on a fresh one
    # Let's do a robust approach: compress and index in sequence
    bcftools view -Oz -o "${RESULTS_DIR}/${sample}.vcf.gz" <(samtools view "$bam") 2>/dev/null || true
    
    if [[ ! -e "$bai" ]]; then exit 1; fi # Ensure bai exists before tabix on vcf? No, step 5 did it.
    
    # Actually, let's re-do compression cleanly to ensure we have a valid .vcf.gz for tabix
    bcftools view -Oz -o "${RESULTS_DIR}/${sample}.vcf.gz" <(samtools view "$bam") || exit 1
    
    if ! command -v tabix > /dev/null; then exit 1; fi
    # Check tbi timestamp vs vcf.gz to avoid re-indexing unnecessarily, but ensure it exists
    if [[ ! -e "${RESULTS_DIR}/${sample}.vcf.gz.tbi" ]]; then
        tabix -p vcf "$bam.bai" > /dev/null || exit 1; 
    fi
    
done

# Step 8: Collapse step -> results/collapsed.tsv
if [[ $(bcftools --version | head -n1 | cut -d' ' -f2) < "1.0" ]]; then exit 1; fi

tsv_file="${RESULTS_DIR}/collapsed.tsv"

# Check if tsv exists and is newer than all inputs (idempotency)
if [[ -e "$tsv_file" ]] && \
   (( $(stat -c %Y $tsv_file) > $(stat -c %M "${SAMPLES}[0]".vcf.gz 2>/dev/null || echo 1)) )) ; then
    # Check if all vcf files are newer than tsv, otherwise rebuild
    latest_vcf_time=0
    for sample in "${SAMPLES[@]}"; do
        vcf="${RESULTS_DIR}/${sample}.vcf.gz"
        if [[ -e "$vcf" ]]; then
            ts=$(stat -c %Y $vcf)
            ((ts > latest_vcf_time)) && latest_vcf_time=$ts
        fi
    done
    
    # If tsv is newer than the most recent vcf, skip rebuild. 
    # However, if any input changed (e.g., a new sample added or modified), we should rebuild?
    # The prompt says "Rebuild only if any input VCF is newer than the TSV".
    # So check each:
    
    needs_rebuild=false
    
    for sample in "${SAMPLES[@]}"; do
        vcf="${RESULTS_DIR}/${sample}.vcf.gz"
        tsv_time=$(stat -c %Y $tsv_file)
        if [[ $(stat -c %Y "$vcf") > $tsv_time ]]; then
            needs_rebuild=true
            break
        fi
    done
    
    if ! $needs_rebuild; then exit 0; fi
fi

# Build collapsed.tsv content
tmp_vcf_list=$(mktemp)
for sample in "${SAMPLES[@]}"; do
    vcf="${RESULTS_DIR}/${sample}.vcf.gz"
    bcftools query -f '{\t%CHROM\t%POS\t%REF\tALT\tINFO/AF\n}' "$vcf" >> "$tmp_vcf_list" || exit 1
done

# Write header and data to tsv file (overwrite)
{
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    cat "$tmp_vcf_list"
} > "$tsv_file"

rm -f "$tmp_vcf_list"