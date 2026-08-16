#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Step 2: Reference indexing (idempotent)
if [ ! -f data/ref/chrM.fa.fai ] || [ ! -f data/ref/chrM.fa.amb ]; then
    samtools faidx data/ref/chrM.fa
    bwa index data/ref/chrM.fa
fi

# Step 3-5: Per-sample alignment, sorting, indexing (idempotent)
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    
    if [ ! -f "$bai" ] || [ "data/raw/${sample}_1.fq.gz" -nt "$bai" ] || [ "data/ref/chrM.fa" -nt "$bai" ]; then
        bwa mem -t ${THREADS} \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" \
        | samtools sort -@ ${THREADS} -o "${bam}" -
        
        samtools index -@ ${THREADS} "${bam}"
    fi
done

# Step 6-7: Variant calling, compression, indexing (idempotent)
for sample in "${SAMPLES[@]}"; do
    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"
    
    if [ ! -f "$tbi" ] || [ "results/${sample}.bam" -nt "$tbi" ]; then
        lofreq call-parallel --pp-threads ${THREADS} --verbose \
            --ref data/ref/chrM.fa \
            --out "results/${sample}.vcf" \
            --sig \
            --bonf \
            "results/${sample}.bam"
        
        bgzip -c "results/${sample}.vcf" > "${vcf_gz}"
        tabix -p vcf "${vcf_gz}"
        
        rm -f "results/${sample}.vcf"
    fi
done

# Step 8: Collapse step (idempotent)
collapsed="results/collapsed.tsv"
need_collapse=false

for sample in "${SAMPLES[@]}"; do
    if [ ! -f "$collapsed" ] || [ "results/${sample}.vcf.gz.tbi" -nt "$collapsed" ]; then
        need_collapse=true
        break
    fi
done

if $need_collapse; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "${collapsed}"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz" >> "${collapsed}"
    done
fi