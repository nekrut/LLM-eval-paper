#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Step 2: Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.amb ]; then
    bwa index data/ref/chrM.fa
fi

# Step 3-5: Per-sample alignment, sorting, indexing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    # Skip if BAM and BAI already exist (idempotency)
    if [ -f "$bam" ] && [ -f "$bai" ]; then
        :
    else
        # Step 3 & 4: Align and sort
        bwa mem -t ${THREADS} \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" \
            | samtools sort -@ ${THREADS} -o "${bam}" -
        
        # Step 5: Index BAM
        samtools index -@ ${THREADS} "${bam}"
    fi

    # Skip if VCF and TBI already exist (idempotency)
    if [ -f "$vcf_gz" ] && [ -f "$tbi" ]; then
        :
    else
        # Step 6: Variant calling with lofreq
        lofreq call-parallel --pp-threads ${THREADS} --verbose \
            --ref data/ref/chrM.fa \
            --out "results/${sample}.vcf" \
            --sig \
            --bonf \
            "${bam}"

        # Step 7: Compress and index VCF
        bgzip -c "results/${sample}.vcf" > "${vcf_gz}"
        tabix -p vcf "${vcf_gz}"
        
        # Remove intermediate uncompressed VCF
        rm -f "results/${sample}.vcf"
    fi
done

# Step 8: Collapse step -> results/collapsed.tsv
collapsed="results/collapsed.tsv"
need_rebuild=0

if [ ! -f "$collapsed" ]; then
    need_rebuild=1
else
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="results/${sample}.vcf.gz"
        if [ "$vcf_gz" -nt "$collapsed" ]; then
            need_rebuild=1
            break
        fi
    done
fi

if [ "$need_rebuild" -eq 1 ]; then
    # Write header
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "$collapsed"
    
    # Append data for each sample
    for sample in "${SAMPLES[@]}"; do
        vcf_gz="results/${sample}.vcf.gz"
        if [ -f "$vcf_gz" ]; then
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${vcf_gz}" >> "$collapsed"
        fi
    done
fi